import { registerAs } from '@nestjs/config';
import { REDIS_HOST, REDIS_PORT, REDIS_PASSWORD, REDIS_TTL } from '@/utils';

export const CacheConfigName = 'redis';

export interface CacheConfig {
  host: string;
  port: number;
  password: string;
  ttl: number;
}

export default registerAs(CacheConfigName, () => ({
  host: REDIS_HOST,
  port: REDIS_PORT,
  password: REDIS_PASSWORD,
  ttl: REDIS_TTL,
}));
