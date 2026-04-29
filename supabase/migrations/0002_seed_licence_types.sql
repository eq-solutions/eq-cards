-- 0002_seed_licence_types.sql
-- Pre-seed common Australian tradie licence types.
-- Custom user-added types live in the same table with is_custom = true.

insert into public.licence_types (code, label, requires_state, default_validity_months, is_custom)
values
  ('white_card',         'White Card (Construction Induction)', false, null, false),
  ('driver_licence',     'Driver Licence',                       true,  null, false),
  ('first_aid',          'First Aid (HLTAID011)',                false, 36,   false),
  ('cpr',                'CPR (HLTAID009)',                      false, 12,   false),
  ('working_at_heights', 'Working at Heights',                   false, 24,   false),
  ('confined_space',     'Confined Space Entry',                 false, 24,   false),
  ('ewp',                'Elevated Work Platform (EWP)',         false, 60,   false),
  ('forklift_hrwl',      'Forklift / High Risk Work Licence',    true,  null, false),
  ('test_and_tag',       'Test and Tag',                         false, 12,   false),
  ('electrical_licence', 'Electrical Licence',                   true,  null, false),
  ('medicare',           'Medicare Card',                        false, null, false),
  ('asbestos_awareness', 'Asbestos Awareness',                   false, 60,   false),
  ('traffic_control',    'Traffic Control',                      false, 36,   false)
on conflict do nothing;
