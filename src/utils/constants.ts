import 'dotenv/config';

// Environment
export const NODE_ENV = process.env.NODE_ENV || 'development';
export const TZ = process.env.TZ || 'UTC';
export const PORT = parseInt(process.env.PORT || '3000', 10);
export const CORS_URL = process.env.CORS_URL || '*';

// Database / Supabase
export const DATABASE_URL = process.env.DATABASE_URL || '';
export const DIRECT_URL = process.env.DIRECT_URL || '';
export const SUPABASE_URL = process.env.SUPABASE_URL || '';
export const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';

// Redis
export const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
export const REDIS_PORT = parseInt(process.env.REDIS_PORT || '6379', 10);
export const REDIS_PASSWORD = process.env.REDIS_PASSWORD || '';
export const REDIS_TTL = parseInt(process.env.REDIS_TTL || '60', 10);

// Log
export const LOG_DIR = process.env.LOG_DIR || 'logs';

// Token Validity Info
export const ACCESS_TOKEN_VALIDITY_SEC = parseInt(
  process.env.ACCESS_TOKEN_VALIDITY_SEC || '172800',
  10,
);
export const REFRESH_TOKEN_VALIDITY_SEC = parseInt(
  process.env.REFRESH_TOKEN_VALIDITY_SEC || '604800',
  10,
);
export const TOKEN_ISSUER = process.env.TOKEN_ISSUER || 'api.dev.xyz.com';
export const TOKEN_AUDIENCE = process.env.TOKEN_AUDIENCE || 'xyz.com';

// Cache Configuration
export const CONTENT_CACHE_DURATION_MILLIS = parseInt(
  process.env.CONTENT_CACHE_DURATION_MILLIS || '600000',
  10,
);

// Firebase
export const FIREBASE_DB_URL = process.env.FIREBASE_DB_URL || '';

// Notification settings
export const NOTIFICATION_DRY_RUN = process.env.NOTIFICATION_DRY_RUN === 'true';
export const NOTIFICATION_VIEWS_INTERVAL = parseInt(
  process.env.NOTIFICATION_VIEWS_INTERVAL || '20',
  10,
);

// Storage configuration
export const DISK_STORAGE_PATH = process.env.DISK_STORAGE_PATH || 'disk';
export const IMAGE_CACHE_DURATION = parseInt(
  process.env.IMAGE_CACHE_DURATION || '31536000',
  10,
);

// Keys path
export const AUTH_PUBLIC_KEY_PATH =
  process.env.AUTH_PUBLIC_KEY_PATH || 'keys/public.pem';
export const AUTH_PRIVATE_KEY_PATH =
  process.env.AUTH_PRIVATE_KEY_PATH || 'keys/private.pem';
