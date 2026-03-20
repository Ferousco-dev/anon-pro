# Supabase Deployment Steps (Analytics + ImageKit)

## Prerequisites

- Supabase CLI installed and logged in: `supabase login`
- Project is linked locally: `supabase link --project-ref <your-ref>`

## Apply migrations (adds user_activity + admin_user_stats RPC)

```
supabase db push
```

## Set Edge Function secrets

```
supabase secrets set IMAGEKIT_PUBLIC_KEY=your_public_key IMAGEKIT_PRIVATE_KEY=your_private_key
```

## Configure database runtime settings (no hardcoded URLs/passcodes)

Run in SQL editor:

```
alter database postgres set "app.settings.supabase_url" to "https://<your-project-ref>.supabase.co";
alter database postgres set "app.settings.admin_passcode" to "<your-admin-passcode>";
```

## Deploy ImageKit functions

```
supabase functions deploy imagekit-signature
supabase functions deploy imagekit-delete
```

## Verify admin analytics RPC

Run in SQL editor:

```
select public.admin_user_stats();
```

## Ensure admin role

Make sure your admin user has `role = 'admin'` in `public.users` so the RPC returns data.

supabase secrets set IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= IMAGEKIT_PRIVATE_KEY=YOUR_IMAGEKIT_PRIVATE_KEY
