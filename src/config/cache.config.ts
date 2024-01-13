import { registerAs } from '@nestjs/config';

export const CacheConfigName = 'redis';

export interface CacheConfig {
  host: string;
  port: number;
  password: string;
  ttl: number;
}

export default registerAs(CacheConfigName, () => ({
  host: process.env.REDIS_HOST || '',
  port: process.env.REDIS_PORT || '',
  password: process.env.REDIS_PASSWORD || '',
  minPoolSize: parseInt(process.env.REDIS_TTL || '60'),
}));
