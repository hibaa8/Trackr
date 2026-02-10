-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.calendar_blocks (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  start_at text NOT NULL,
  end_at text NOT NULL,
  title text NOT NULL,
  source text NOT NULL,
  status text NOT NULL,
  CONSTRAINT calendar_blocks_pkey PRIMARY KEY (id),
  CONSTRAINT calendar_blocks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.checkins (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  checkin_date text NOT NULL,
  weight_kg double precision,
  mood text,
  notes text,
  CONSTRAINT checkins_pkey PRIMARY KEY (id),
  CONSTRAINT checkins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.health_activity (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  date text NOT NULL,
  steps integer NOT NULL,
  calories_burned integer NOT NULL,
  workouts_summary text,
  source text NOT NULL,
  CONSTRAINT health_activity_pkey PRIMARY KEY (id),
  CONSTRAINT health_activity_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.meal_logs (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  logged_at text NOT NULL,
  photo_path text,
  description text,
  calories integer NOT NULL,
  protein_g integer NOT NULL,
  carbs_g integer NOT NULL,
  fat_g integer NOT NULL,
  confidence double precision,
  confirmed integer NOT NULL,
  CONSTRAINT meal_logs_pkey PRIMARY KEY (id),
  CONSTRAINT meal_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.plan_checkpoints (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  plan_id integer,
  checkpoint_week integer NOT NULL,
  expected_weight_kg double precision NOT NULL,
  min_weight_kg double precision NOT NULL,
  max_weight_kg double precision NOT NULL,
  template_id integer,
  CONSTRAINT plan_checkpoints_pkey PRIMARY KEY (id),
  CONSTRAINT plan_checkpoints_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id),
  CONSTRAINT plan_checkpoints_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.plan_templates(id)
);
CREATE TABLE public.plan_overrides (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  plan_id integer,
  date text NOT NULL,
  override_type text NOT NULL,
  workout_json text,
  calorie_target integer,
  calorie_delta integer,
  reason text,
  created_at text NOT NULL,
  template_id integer,
  CONSTRAINT plan_overrides_pkey PRIMARY KEY (id),
  CONSTRAINT plan_overrides_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id),
  CONSTRAINT plan_overrides_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.plan_templates(id)
);
CREATE TABLE public.plan_template_days (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  template_id integer NOT NULL,
  day_index integer NOT NULL,
  workout_json text,
  calorie_delta integer,
  notes text,
  CONSTRAINT plan_template_days_pkey PRIMARY KEY (id),
  CONSTRAINT plan_template_days_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.plan_templates(id)
);
CREATE TABLE public.plan_templates (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  plan_id integer,
  cycle_length_days integer NOT NULL,
  timezone text,
  default_calories integer NOT NULL,
  default_protein_g integer NOT NULL,
  default_carbs_g integer NOT NULL,
  default_fat_g integer NOT NULL,
  created_at text NOT NULL,
  user_id integer,
  start_date text,
  end_date text,
  daily_calorie_target integer,
  protein_g integer,
  carbs_g integer,
  fat_g integer,
  status text,
  CONSTRAINT plan_templates_pkey PRIMARY KEY (id),
  CONSTRAINT plan_templates_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id),
  CONSTRAINT plan_templates_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.plans (
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
CREATE TABLE public.points (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  points integer NOT NULL,
  reason text NOT NULL,
  created_at text NOT NULL,
  CONSTRAINT points_pkey PRIMARY KEY (id),
  CONSTRAINT points_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.reminders (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  reminder_type text NOT NULL,
  scheduled_at text NOT NULL,
  status text NOT NULL,
  channel text NOT NULL,
  related_plan_override_id integer,
  CONSTRAINT reminders_pkey PRIMARY KEY (id),
  CONSTRAINT reminders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT reminders_related_plan_override_id_fkey FOREIGN KEY (related_plan_override_id) REFERENCES public.plan_overrides(id)
);
CREATE TABLE public.streaks (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  streak_type text NOT NULL,
  current_count integer NOT NULL,
  best_count integer NOT NULL,
  last_date text NOT NULL,
  CONSTRAINT streaks_pkey PRIMARY KEY (id),
  CONSTRAINT streaks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.user_preferences (
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
CREATE TABLE public.users (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  email text NOT NULL UNIQUE,
  name text NOT NULL,
  gender text,
  birthdate text,
  height_cm double precision,
  weight_kg double precision,
  created_at text NOT NULL,
  age_years integer,
  agent_name text,
  CONSTRAINT users_pkey PRIMARY KEY (id)
);
CREATE TABLE public.workout_sessions (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id integer NOT NULL,
  date text NOT NULL,
  workout_type text NOT NULL,
  duration_min integer NOT NULL,
  calories_burned integer,
  notes text,
  completed integer NOT NULL,
  source text NOT NULL,
  CONSTRAINT workout_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT workout_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);