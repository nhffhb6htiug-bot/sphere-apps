-- Portfolio category metadata for editor uploads; backwards compatible with existing rows.
-- Older portfolio records are classified as Other until the editor adds categorized work.
alter table public.sp_portfolio
  add column if not exists category text not null default 'Other';
comment on column public.sp_portfolio.category is 'Editor-selected creative category. Legacy portfolio items use Other.';
