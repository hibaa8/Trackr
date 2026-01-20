## AI Trainer Agent

Brief CLI-based AI trainer with plan generation, workout logging, and meal logging.

### Requirements
- Python 3.12+
- Virtual environment (recommended)

### Setup
1. Create and activate a virtual environment.
2. Install dependencies:
   - `pip install -r requirements.txt`
3. Configure environment variables in a `.env` file if needed:
   - `OPENAI_API_KEY`
   - `TAVILY_API_KEY` (optional, for `search_web`)
   - `REDIS_URL` or `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN`

### Run
From the repo root:
- `python -m agent.cli`

Type `exit` to quit.
