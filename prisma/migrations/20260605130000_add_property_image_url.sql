-- Add image_url column to accommodation_properties
ALTER TABLE public.accommodation_properties
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Create public storage bucket for property images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'properties',
  'properties',
  true,
  1048576,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies
CREATE POLICY "properties_images_public_read"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'properties');

CREATE POLICY "properties_images_auth_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'properties');

CREATE POLICY "properties_images_auth_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'properties');

CREATE POLICY "properties_images_auth_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'properties');
