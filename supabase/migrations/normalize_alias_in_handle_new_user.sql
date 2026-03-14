-- Normalize/fallback alias during signup to avoid empty/duplicate issues

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_alias text;
  v_display_name text;
  v_email_local text;
  v_suffix int := 0;
  v_candidate text;
BEGIN
  -- Normalize alias: trim, lower, and fall back to email local-part
  v_alias := lower(btrim(coalesce(NEW.raw_user_meta_data->>'alias', '')));

  v_email_local := split_part(coalesce(NEW.email, ''), '@', 1);
  IF v_alias = '' THEN
    v_alias := lower(btrim(v_email_local));
  END IF;

  v_display_name := coalesce(
    NULLIF(NEW.raw_user_meta_data->>'display_name', ''),
    NULLIF(NEW.raw_user_meta_data->>'alias', ''),
    v_alias,
    'User'
  );

  -- Ensure alias is unique by appending a numeric suffix when needed
  v_candidate := v_alias;
  WHILE EXISTS (SELECT 1 FROM public.users WHERE alias = v_candidate) LOOP
    v_suffix := v_suffix + 1;
    v_candidate := v_alias || v_suffix::text;
  END LOOP;
  v_alias := v_candidate;

  INSERT INTO public.users (id, email, full_name, alias, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name',
    v_alias,
    v_display_name
  );

  RETURN NEW;
END;
$function$;
