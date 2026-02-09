-- Supabase schema updates for onboarding data + plans
-- Safe to run multiple times.

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS gender text,
    ADD COLUMN IF NOT EXISTS birthdate text,
    ADD COLUMN IF NOT EXISTS height_cm double precision,
    ADD COLUMN IF NOT EXISTS weight_kg double precision;

CREATE TABLE IF NOT EXISTS public.user_preferences (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    user_id integer NOT NULL UNIQUE,
    goal_type text NOT NULL,
    target_weight_kg double precision,
    weekly_weight_change_kg double precision,
    activity_level text,
    dietary_preferences text,
    workout_preferences text,
    timezone text,
    created_at text NOT NULL,
    CONSTRAINT user_preferences_pkey PRIMARY KEY (id),
    CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE IF NOT EXISTS public.plans (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    user_id integer NOT NULL,
    start_date text NOT NULL,
    end_date text NOT NULL,
    daily_calorie_target integer NOT NULL,
    protein_g integer NOT NULL,
    carbs_g integer NOT NULL,
    fat_g integer NOT NULL,
    status text NOT NULL,
    created_at text NOT NULL,
    CONSTRAINT plans_pkey PRIMARY KEY (id),
    CONSTRAINT plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE IF NOT EXISTS public.plan_templates (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    plan_id integer NOT NULL,
    cycle_length_days integer NOT NULL,
    timezone text,
    default_calories integer NOT NULL,
    default_protein_g integer NOT NULL,
    default_carbs_g integer NOT NULL,
    default_fat_g integer NOT NULL,
    created_at text NOT NULL,
    CONSTRAINT plan_templates_pkey PRIMARY KEY (id),
    CONSTRAINT plan_templates_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id)
);

ALTER TABLE public.plan_templates
    ALTER COLUMN plan_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS user_id integer,
    ADD COLUMN IF NOT EXISTS start_date text,
    ADD COLUMN IF NOT EXISTS end_date text,
    ADD COLUMN IF NOT EXISTS daily_calorie_target integer,
    ADD COLUMN IF NOT EXISTS protein_g integer,
    ADD COLUMN IF NOT EXISTS carbs_g integer,
    ADD COLUMN IF NOT EXISTS fat_g integer,
    ADD COLUMN IF NOT EXISTS status text;

CREATE TABLE IF NOT EXISTS public.plan_template_days (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    template_id integer NOT NULL,
    day_index integer NOT NULL,
    workout_json text,
    calorie_delta integer,
    notes text,
    CONSTRAINT plan_template_days_pkey PRIMARY KEY (id),
    CONSTRAINT plan_template_days_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.plan_templates(id)
);

CREATE TABLE IF NOT EXISTS public.plan_overrides (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    plan_id integer NOT NULL,
    date text NOT NULL,
    override_type text NOT NULL,
    workout_json text,
    calorie_target integer,
    calorie_delta integer,
    reason text,
    created_at text NOT NULL,
    CONSTRAINT plan_overrides_pkey PRIMARY KEY (id),
    CONSTRAINT plan_overrides_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id)
);

ALTER TABLE public.plan_overrides
    ALTER COLUMN plan_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS template_id integer;

CREATE TABLE IF NOT EXISTS public.plan_checkpoints (
    id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    plan_id integer NOT NULL,
    checkpoint_week integer NOT NULL,
    expected_weight_kg double precision NOT NULL,
    min_weight_kg double precision NOT NULL,
    max_weight_kg double precision NOT NULL,
    CONSTRAINT plan_checkpoints_pkey PRIMARY KEY (id),
    CONSTRAINT plan_checkpoints_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id)
);

ALTER TABLE public.plan_checkpoints
    ALTER COLUMN plan_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS template_id integer;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'plan_templates_user_id_fkey'
    ) THEN
        ALTER TABLE public.plan_templates
            ADD CONSTRAINT plan_templates_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES public.users(id);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'plan_overrides_template_id_fkey'
    ) THEN
        ALTER TABLE public.plan_overrides
            ADD CONSTRAINT plan_overrides_template_id_fkey
            FOREIGN KEY (template_id) REFERENCES public.plan_templates(id);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'plan_checkpoints_template_id_fkey'
    ) THEN
        ALTER TABLE public.plan_checkpoints
            ADD CONSTRAINT plan_checkpoints_template_id_fkey
            FOREIGN KEY (template_id) REFERENCES public.plan_templates(id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plans_user_status ON public.plans (user_id, status);
CREATE INDEX IF NOT EXISTS idx_plan_templates_user_status ON public.plan_templates (user_id, status, start_date);
CREATE INDEX IF NOT EXISTS idx_plan_overrides_template_date ON public.plan_overrides (template_id, date);
CREATE UNIQUE INDEX IF NOT EXISTS idx_plan_overrides_template_date_unique ON public.plan_overrides (template_id, date);
CREATE INDEX IF NOT EXISTS idx_plan_checkpoints_template_week ON public.plan_checkpoints (template_id, checkpoint_week);