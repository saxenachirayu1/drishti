# Deploying the API

The service is a single container. It reads its port from `$PORT`, so it runs
on any host without modification, and every secret comes from the environment.

Pick one of the two routes below. Hugging Face Spaces needs no credit card,
which is why it is first; Code Engine is the hackathon's intended target and
the steps are the same shape.

## Before you deploy, either way

Set these in the host's secrets or environment:

| Variable | Value | Why |
| --- | --- | --- |
| `SUPABASE_URL` | `https://ofudjcrzdgltpoyavibr.supabase.co` | Member A's project |
| `SUPABASE_SERVICE_ROLE_KEY` | from Member A | server-side access |
| `SUPABASE_JWT_SECRET` | from Member A | verifies the legacy service token |
| `REPO_BACKEND` | `supabase` | makes a missing key a loud error, not a silent fallback to seed data |
| `ALLOWED_ORIGINS` | `https://saxenachirayu1.github.io` | **set this.** Left at `*`, any page can drive the API with a visitor's token |
| `WATSONX_API_KEY` | optional | without it, complaints use the template drafter |
| `WATSONX_PROJECT_ID` | optional | |
| `RESEND_API_KEY` | optional | without it, "email" is logged to the console |

Never set `DEV_ROLE` or `AUTH_BYPASS` in a deployed service. With
`SUPABASE_URL` present the API enforces real tokens; those two switch that off.

Check it afterwards: `GET /health` reports the backend, the auth mode and
`config_problems`. That list should be empty — it will tell you, for instance,
if `ALLOWED_ORIGINS` is still `*`.

## Route A — Hugging Face Spaces (free, no card)

1. Create a free account at huggingface.co (email only).
2. **New Space** → SDK **Docker** → **Blank** → visibility **Public**.
3. Push the contents of `api/` to the Space repo, with a `README.md` at its
   root carrying this front matter so the Space knows the port:

   ```
   ---
   title: Drishti API
   sdk: docker
   app_port: 7860
   ---
   ```

   ```bash
   git clone https://huggingface.co/spaces/<you>/drishti-api
   cp -r api/* drishti-api/          # Dockerfile, app/, fonts/, requirements.txt
   cd drishti-api
   # add the README.md front matter above, then
   git add -A && git commit -m "Drishti API" && git push
   ```

   Do **not** copy `api/.env` — the Space has its own secrets UI.
4. Space **Settings → Variables and secrets** → add the table above.
5. The Space builds and starts. Your URL is
   `https://<you>-drishti-api.hf.space`. Check `/health` and `/docs`.

Spaces idle out after inactivity and cold-start in roughly 30 seconds. Wake it
before a demo by loading `/health`.

## Route B — IBM Code Engine (needs an IBM Cloud account)

```bash
ibmcloud ce project create --name drishti
ibmcloud ce application create --name drishti-api \
  --build-source ./api --port 8080 \
  --env PORT=8080 \
  --env REPO_BACKEND=supabase \
  --env ALLOWED_ORIGINS=https://saxenachirayu1.github.io \
  --env-from-secret drishti-secrets
```

Put `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET` and the
watsonx keys in the `drishti-secrets` secret rather than on the command line.
`ibmcloud ce application get --name drishti-api` prints the public URL.

## After either route: point the dashboard at it

1. Repo **Settings → Secrets and variables → Actions → Variables** → add
   `API_BASE_URL` with the deployed URL (no trailing slash).
2. Re-run the `app-web` workflow. The published dashboard then calls the API
   instead of falling back to its own local logic.
3. Confirm: open the dashboard, sign in, and check the Network tab shows calls
   to the deployed host.

## Verifying the deployment

```bash
curl https://<your-host>/health          # db, auth, config_problems
curl -i https://<your-host>/sites        # expect 401 without a token
curl -i -X OPTIONS https://<your-host>/sites \
  -H 'Origin: https://saxenachirayu1.github.io' \
  -H 'Access-Control-Request-Method: GET'   # expect the allow-origin header
```

A `401` on `/sites` is the service working: auth switches on automatically once
a Supabase project is configured.

## Not yet verified

The container image has **not been built**, because no container runtime was
available on the machine these changes were made on. The start command and the
`$PORT` handling were tested by running the same command directly
(`PORT=7860 uvicorn app.main:app --host 0.0.0.0 --port ${PORT}` → healthy), and
CORS was tested against both an allowed and a disallowed origin. Expect to fix
something on the first build — most likely a missing system package.
