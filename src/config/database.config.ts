import { registerAs } from '@nestjs/config';
import {
  DATABASE_URL,
  DIRECT_URL,
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
} from '@/utils';

export const DatabaseConfigName = 'database';

export interface DatabaseConfig {
  url: string;
  directUrl?: string;
  supabaseUrl?: string;
  supabaseAnonKey?: string;
}

export default registerAs(DatabaseConfigName, () => ({
  url: DATABASE_URL,
  directUrl: DIRECT_URL,
  supabaseUrl: SUPABASE_URL,
  supabaseAnonKey: SUPABASE_ANON_KEY,
}));
