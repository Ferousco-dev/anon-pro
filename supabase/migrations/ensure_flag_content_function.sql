-- Ensure moderation keyword flagging function exists (idempotent)

CREATE OR REPLACE FUNCTION public.flag_content_by_keywords(
  p_content_type TEXT,
  p_content_id UUID,
  p_user_id UUID,
  p_text TEXT
) RETURNS VOID AS $$
DECLARE
  v_keyword TEXT;
BEGIN
  SELECT keyword INTO v_keyword
  FROM public.moderation_keywords
  WHERE is_active = TRUE
    AND p_text ILIKE '%' || keyword || '%'
  LIMIT 1;

  IF v_keyword IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.content_flags (content_type, content_id, user_id, matched_keyword)
  VALUES (p_content_type, p_content_id, p_user_id, v_keyword);

  PERFORM public.apply_strike(p_user_id);
END;
$$ LANGUAGE plpgsql;

-- Overload for legacy integer IDs (avoid runtime errors on triggers)
CREATE OR REPLACE FUNCTION public.flag_content_by_keywords(
  p_content_type TEXT,
  p_content_id BIGINT,
  p_user_id UUID,
  p_text TEXT
) RETURNS VOID AS $$
DECLARE
  v_keyword TEXT;
BEGIN
  SELECT keyword INTO v_keyword
  FROM public.moderation_keywords
  WHERE is_active = TRUE
    AND p_text ILIKE '%' || keyword || '%'
  LIMIT 1;

  IF v_keyword IS NULL THEN
    RETURN;
  END IF;

  -- Skip content_flags insert since content_id is not UUID.
  PERFORM public.apply_strike(p_user_id);
END;
$$ LANGUAGE plpgsql;
