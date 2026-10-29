-- Portfolio category labels; existing portfolios remain visible under "Other".
-- Nullable for backwards compatibility with older app versions and older rows.
ALTER TABLE public.sp_portfolio
  ADD COLUMN IF NOT EXISTS category text;
COMMENT ON COLUMN public.sp_portfolio.category
  IS 'Editing category selected by the editor; NULL for pre-existing portfolio work.';
