-- Migration: Accommodation booking sources, countries, and views
-- Created: 2026-05-07
-- Depends on: 20260505120000_create_accommodation_schema.sql
-- Description:
--   1. Creates the `countries` table (ISO 3166-1 alpha-2) with all ~195 world countries
--   2. Creates the `accommodation_booking_sources` lookup table
--   3. Adds source_id + guest_country_id to accommodation_bookings
--   4. Adds country_id to clients
--   5. Creates accommodation_bookings_view (rich join view)
--   6. Creates accommodation_property_bookings_view (summary view per property)

-- ============================================================
-- 1. countries table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.countries (
  id         SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT NOT NULL,
  iso_code   CHAR(2) NOT NULL,
  phone_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT countries_iso_code_unique UNIQUE (iso_code)
);

-- Enable RLS
ALTER TABLE public.countries ENABLE ROW LEVEL SECURITY;

-- Publicly readable (no auth required)
DROP POLICY IF EXISTS "Countries are publicly readable" ON public.countries;
CREATE POLICY "Countries are publicly readable"
  ON public.countries FOR SELECT
  USING (true);

GRANT SELECT ON public.countries TO authenticated;
GRANT SELECT ON public.countries TO anon;

-- Seed all ~195 world countries (ISO 3166-1 alpha-2 + calling codes)
INSERT INTO public.countries (name, iso_code, phone_code) VALUES
  ('Afghanistan',                           'AF', '+93'),
  ('Albania',                               'AL', '+355'),
  ('Algeria',                               'DZ', '+213'),
  ('Andorra',                               'AD', '+376'),
  ('Angola',                                'AO', '+244'),
  ('Antigua and Barbuda',                   'AG', '+1-268'),
  ('Argentina',                             'AR', '+54'),
  ('Armenia',                               'AM', '+374'),
  ('Australia',                             'AU', '+61'),
  ('Austria',                               'AT', '+43'),
  ('Azerbaijan',                            'AZ', '+994'),
  ('Bahamas',                               'BS', '+1-242'),
  ('Bahrain',                               'BH', '+973'),
  ('Bangladesh',                            'BD', '+880'),
  ('Barbados',                              'BB', '+1-246'),
  ('Belarus',                               'BY', '+375'),
  ('Belgium',                               'BE', '+32'),
  ('Belize',                                'BZ', '+501'),
  ('Benin',                                 'BJ', '+229'),
  ('Bhutan',                                'BT', '+975'),
  ('Bolivia',                               'BO', '+591'),
  ('Bosnia and Herzegovina',                'BA', '+387'),
  ('Botswana',                              'BW', '+267'),
  ('Brazil',                                'BR', '+55'),
  ('Brunei',                                'BN', '+673'),
  ('Bulgaria',                              'BG', '+359'),
  ('Burkina Faso',                          'BF', '+226'),
  ('Burundi',                               'BI', '+257'),
  ('Cabo Verde',                            'CV', '+238'),
  ('Cambodia',                              'KH', '+855'),
  ('Cameroon',                              'CM', '+237'),
  ('Canada',                                'CA', '+1'),
  ('Central African Republic',              'CF', '+236'),
  ('Chad',                                  'TD', '+235'),
  ('Chile',                                 'CL', '+56'),
  ('China',                                 'CN', '+86'),
  ('Colombia',                              'CO', '+57'),
  ('Comoros',                               'KM', '+269'),
  ('Congo (Brazzaville)',                   'CG', '+242'),
  ('Congo (Kinshasa)',                      'CD', '+243'),
  ('Costa Rica',                            'CR', '+506'),
  ('Croatia',                               'HR', '+385'),
  ('Cuba',                                  'CU', '+53'),
  ('Cyprus',                                'CY', '+357'),
  ('Czech Republic',                        'CZ', '+420'),
  ('Denmark',                               'DK', '+45'),
  ('Djibouti',                              'DJ', '+253'),
  ('Dominica',                              'DM', '+1-767'),
  ('Dominican Republic',                    'DO', '+1-809'),
  ('Ecuador',                               'EC', '+593'),
  ('Egypt',                                 'EG', '+20'),
  ('El Salvador',                           'SV', '+503'),
  ('Equatorial Guinea',                     'GQ', '+240'),
  ('Eritrea',                               'ER', '+291'),
  ('Estonia',                               'EE', '+372'),
  ('Eswatini',                              'SZ', '+268'),
  ('Ethiopia',                              'ET', '+251'),
  ('Fiji',                                  'FJ', '+679'),
  ('Finland',                               'FI', '+358'),
  ('France',                                'FR', '+33'),
  ('Gabon',                                 'GA', '+241'),
  ('Gambia',                                'GM', '+220'),
  ('Georgia',                               'GE', '+995'),
  ('Germany',                               'DE', '+49'),
  ('Ghana',                                 'GH', '+233'),
  ('Greece',                                'GR', '+30'),
  ('Grenada',                               'GD', '+1-473'),
  ('Guatemala',                             'GT', '+502'),
  ('Guinea',                                'GN', '+224'),
  ('Guinea-Bissau',                         'GW', '+245'),
  ('Guyana',                                'GY', '+592'),
  ('Haiti',                                 'HT', '+509'),
  ('Honduras',                              'HN', '+504'),
  ('Hungary',                               'HU', '+36'),
  ('Iceland',                               'IS', '+354'),
  ('India',                                 'IN', '+91'),
  ('Indonesia',                             'ID', '+62'),
  ('Iran',                                  'IR', '+98'),
  ('Iraq',                                  'IQ', '+964'),
  ('Ireland',                               'IE', '+353'),
  ('Israel',                                'IL', '+972'),
  ('Italy',                                 'IT', '+39'),
  ('Jamaica',                               'JM', '+1-876'),
  ('Japan',                                 'JP', '+81'),
  ('Jordan',                                'JO', '+962'),
  ('Kazakhstan',                            'KZ', '+7'),
  ('Kenya',                                 'KE', '+254'),
  ('Kiribati',                              'KI', '+686'),
  ('Kuwait',                                'KW', '+965'),
  ('Kyrgyzstan',                            'KG', '+996'),
  ('Laos',                                  'LA', '+856'),
  ('Latvia',                                'LV', '+371'),
  ('Lebanon',                               'LB', '+961'),
  ('Lesotho',                               'LS', '+266'),
  ('Liberia',                               'LR', '+231'),
  ('Libya',                                 'LY', '+218'),
  ('Liechtenstein',                         'LI', '+423'),
  ('Lithuania',                             'LT', '+370'),
  ('Luxembourg',                            'LU', '+352'),
  ('Madagascar',                            'MG', '+261'),
  ('Malawi',                                'MW', '+265'),
  ('Malaysia',                              'MY', '+60'),
  ('Maldives',                              'MV', '+960'),
  ('Mali',                                  'ML', '+223'),
  ('Malta',                                 'MT', '+356'),
  ('Marshall Islands',                      'MH', '+692'),
  ('Mauritania',                            'MR', '+222'),
  ('Mauritius',                             'MU', '+230'),
  ('Mexico',                                'MX', '+52'),
  ('Micronesia',                            'FM', '+691'),
  ('Moldova',                               'MD', '+373'),
  ('Monaco',                                'MC', '+377'),
  ('Mongolia',                              'MN', '+976'),
  ('Montenegro',                            'ME', '+382'),
  ('Morocco',                               'MA', '+212'),
  ('Mozambique',                            'MZ', '+258'),
  ('Myanmar',                               'MM', '+95'),
  ('Namibia',                               'NA', '+264'),
  ('Nauru',                                 'NR', '+674'),
  ('Nepal',                                 'NP', '+977'),
  ('Netherlands',                           'NL', '+31'),
  ('New Zealand',                           'NZ', '+64'),
  ('Nicaragua',                             'NI', '+505'),
  ('Niger',                                 'NE', '+227'),
  ('Nigeria',                               'NG', '+234'),
  ('North Korea',                           'KP', '+850'),
  ('North Macedonia',                       'MK', '+389'),
  ('Norway',                                'NO', '+47'),
  ('Oman',                                  'OM', '+968'),
  ('Pakistan',                              'PK', '+92'),
  ('Palau',                                 'PW', '+680'),
  ('Palestine',                             'PS', '+970'),
  ('Panama',                                'PA', '+507'),
  ('Papua New Guinea',                      'PG', '+675'),
  ('Paraguay',                              'PY', '+595'),
  ('Peru',                                  'PE', '+51'),
  ('Philippines',                           'PH', '+63'),
  ('Poland',                                'PL', '+48'),
  ('Portugal',                              'PT', '+351'),
  ('Qatar',                                 'QA', '+974'),
  ('Romania',                               'RO', '+40'),
  ('Russia',                                'RU', '+7'),
  ('Rwanda',                                'RW', '+250'),
  ('Saint Kitts and Nevis',                 'KN', '+1-869'),
  ('Saint Lucia',                           'LC', '+1-758'),
  ('Saint Vincent and the Grenadines',      'VC', '+1-784'),
  ('Samoa',                                 'WS', '+685'),
  ('San Marino',                            'SM', '+378'),
  ('Sao Tome and Principe',                 'ST', '+239'),
  ('Saudi Arabia',                          'SA', '+966'),
  ('Senegal',                               'SN', '+221'),
  ('Serbia',                                'RS', '+381'),
  ('Seychelles',                            'SC', '+248'),
  ('Sierra Leone',                          'SL', '+232'),
  ('Singapore',                             'SG', '+65'),
  ('Slovakia',                              'SK', '+421'),
  ('Slovenia',                              'SI', '+386'),
  ('Solomon Islands',                       'SB', '+677'),
  ('Somalia',                               'SO', '+252'),
  ('South Africa',                          'ZA', '+27'),
  ('South Korea',                           'KR', '+82'),
  ('South Sudan',                           'SS', '+211'),
  ('Spain',                                 'ES', '+34'),
  ('Sri Lanka',                             'LK', '+94'),
  ('Sudan',                                 'SD', '+249'),
  ('Suriname',                              'SR', '+597'),
  ('Sweden',                                'SE', '+46'),
  ('Switzerland',                           'CH', '+41'),
  ('Syria',                                 'SY', '+963'),
  ('Taiwan',                                'TW', '+886'),
  ('Tajikistan',                            'TJ', '+992'),
  ('Tanzania',                              'TZ', '+255'),
  ('Thailand',                              'TH', '+66'),
  ('Timor-Leste',                           'TL', '+670'),
  ('Togo',                                  'TG', '+228'),
  ('Tonga',                                 'TO', '+676'),
  ('Trinidad and Tobago',                   'TT', '+1-868'),
  ('Tunisia',                               'TN', '+216'),
  ('Turkey',                                'TR', '+90'),
  ('Turkmenistan',                          'TM', '+993'),
  ('Tuvalu',                                'TV', '+688'),
  ('Uganda',                                'UG', '+256'),
  ('Ukraine',                               'UA', '+380'),
  ('United Arab Emirates',                  'AE', '+971'),
  ('United Kingdom',                        'GB', '+44'),
  ('United States',                         'US', '+1'),
  ('Uruguay',                               'UY', '+598'),
  ('Uzbekistan',                            'UZ', '+998'),
  ('Vanuatu',                               'VU', '+678'),
  ('Vatican City',                          'VA', '+39'),
  ('Venezuela',                             'VE', '+58'),
  ('Vietnam',                               'VN', '+84'),
  ('Yemen',                                 'YE', '+967'),
  ('Zambia',                                'ZM', '+260'),
  ('Zimbabwe',                              'ZW', '+263')
ON CONFLICT (iso_code) DO NOTHING;

-- ============================================================
-- 2. accommodation_booking_sources table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_booking_sources (
  id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT,
  icon        TEXT,
  sort_order  SMALLINT NOT NULL DEFAULT 99,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accommodation_booking_sources_name_unique UNIQUE (name)
);

-- Enable RLS
ALTER TABLE public.accommodation_booking_sources ENABLE ROW LEVEL SECURITY;

-- Publicly readable
DROP POLICY IF EXISTS "Booking sources are publicly readable" ON public.accommodation_booking_sources;
CREATE POLICY "Booking sources are publicly readable"
  ON public.accommodation_booking_sources FOR SELECT
  USING (true);

GRANT SELECT ON public.accommodation_booking_sources TO authenticated;
GRANT SELECT ON public.accommodation_booking_sources TO anon;

-- Seed booking sources in the specified order
INSERT INTO public.accommodation_booking_sources (name, icon, sort_order) VALUES
  ('Agent',       'user',             1),
  ('Walk-in',     'walk',             2),
  ('Direct',      'phone',            3),
  ('Booking.com', 'globe',            4),
  ('Airbnb',      'home',             5),
  ('Expedia',     'globe',            6),
  ('Phone',       'phone',            7),
  ('Email',       'mail',             8),
  ('Other',       'more-horizontal',  9)
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 3. Add source_id and guest_country_id to accommodation_bookings
-- ============================================================
ALTER TABLE public.accommodation_bookings
  ADD COLUMN IF NOT EXISTS source_id
    SMALLINT REFERENCES public.accommodation_booking_sources(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS guest_country_id
    SMALLINT REFERENCES public.countries(id) ON DELETE SET NULL;

-- Index for filtering bookings by source
CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_source_id
  ON public.accommodation_bookings(source_id);

-- Index for filtering bookings by guest country
CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_guest_country_id
  ON public.accommodation_bookings(guest_country_id);

-- ============================================================
-- 4. Add country_id to clients
-- ============================================================
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS country_id
    SMALLINT REFERENCES public.countries(id) ON DELETE SET NULL;

-- Index for filtering clients by country
CREATE INDEX IF NOT EXISTS idx_clients_country_id
  ON public.clients(country_id);

-- ============================================================
-- 5. View: accommodation_bookings_view
--    Rich join: bookings + property + client + source + country + rooms (JSONB)
-- ============================================================
CREATE OR REPLACE VIEW public.accommodation_bookings_view with (security_invoker = on) AS
SELECT
  -- All columns from accommodation_bookings
  b.*,

  -- Property details
  ap.name                     AS property_name,
  ap.currency                 AS property_currency,
  ap.outlet_id                AS property_outlet_id,

  -- Client details
  c.first_name                AS client_first_name,
  c.last_name                 AS client_last_name,
  c.email                     AS client_email,
  c.contact                   AS client_contact,
  c.nationality               AS client_nationality,
  c.country_id                AS client_country_id,

  -- Booking source details (LEFT JOIN — source_id may be NULL)
  bs.name                     AS source_name,
  bs.icon                     AS source_icon,

  -- Guest country details (LEFT JOIN — guest_country_id may be NULL)
  gc.name                     AS guest_country_name,
  gc.iso_code                 AS guest_country_iso_code,

  -- Booked rooms aggregated as JSONB array
  (
    SELECT COALESCE(json_agg(
      json_build_object(
        'id',              br.id,
        'room_id',         br.room_id,
        'room_type_id',    br.room_type_id,
        'price_per_night', br.price_per_night,
        'nights',          br.nights,
        'subtotal',        br.subtotal,
        'room_number',     ar.room_number,
        'floor',           ar.floor,
        'room_type_name',  art.name
      )
      ORDER BY br.created_at
    ), '[]'::json)
    FROM public.accommodation_booking_rooms br
    LEFT JOIN public.accommodation_rooms     ar  ON ar.id  = br.room_id
    LEFT JOIN public.accommodation_room_types art ON art.id = br.room_type_id
    WHERE br.booking_id = b.id
  )                           AS booking_rooms_json

FROM public.accommodation_bookings          b
JOIN  public.accommodation_properties       ap ON ap.id = b.property_id
JOIN  public.clients                        c  ON c.id  = b.client_id
LEFT JOIN public.accommodation_booking_sources bs ON bs.id = b.source_id
LEFT JOIN public.countries                  gc ON gc.id = b.guest_country_id;

GRANT SELECT ON public.accommodation_bookings_view TO authenticated;

-- ============================================================
-- 6. View: accommodation_property_bookings_view
--    Booking summary per property
-- ============================================================
CREATE OR REPLACE VIEW public.accommodation_property_bookings_view with (security_invoker = on) AS
SELECT
  ap.id           AS property_id,
  ap.name         AS property_name,
  ap.outlet_id    AS outlet_id,
  b.id            AS booking_id,
  b.check_in,
  b.check_out,
  b.status,
  b.total_amount,
  b.currency,
  c.first_name    AS client_first_name,
  c.last_name     AS client_last_name,
  c.email         AS client_email,
  gc.name         AS guest_country_name,
  bs.name         AS source_name
FROM public.accommodation_bookings          b
JOIN  public.accommodation_properties       ap ON ap.id = b.property_id
JOIN  public.clients                        c  ON c.id  = b.client_id
LEFT JOIN public.accommodation_booking_sources bs ON bs.id = b.source_id
LEFT JOIN public.countries                  gc ON gc.id = b.guest_country_id;

GRANT SELECT ON public.accommodation_property_bookings_view TO authenticated;
