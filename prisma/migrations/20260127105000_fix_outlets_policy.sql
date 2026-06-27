DROP POLICY IF EXISTS "Super users and company owners can manage outlets" ON "public"."outlets";

CREATE POLICY "Super users and company owners can manage outlets" ON "public"."outlets"
AS PERMISSIVE FOR ALL
TO authenticated
USING (
  -- 1. If the user is a 'super', they can see/manage everything
  ((SELECT role FROM users WHERE id = auth.uid()) = 'super'::user_role)
  OR
  -- 2. Otherwise, they must be the owner of the specific company
  (EXISTS (SELECT 1 FROM companies WHERE id = outlets.company_id AND created_by = auth.uid()))
)
WITH CHECK (
  -- 1. Super users can insert into any company
  ((SELECT role FROM users WHERE id = auth.uid()) = 'super'::user_role)
  OR
  -- 2. Owners can only insert into companies they created
  (EXISTS (SELECT 1 FROM companies WHERE id = outlets.company_id AND created_by = auth.uid()))
);


-- TODO:: Run this Rename outlet column day_opened_at to day_open
ALTER TABLE outlets RENAME COLUMN day_opened_at TO day_open;

