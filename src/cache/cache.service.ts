import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Inject, Injectable } from '@nestjs/common';
import { Cache } from 'cache-manager';
import { RedisStore } from './redis-cache';

@Injectable()
export class CacheService {
  constructor(@Inject(CACHE_MANAGER) private readonly cache: Cache) {}

  async getValue(key: string): Promise<string | null | undefined> {
    return await this.cache.get(key);
  }

  async setValue(key: string, value: string): Promise<void> {
    await this.cache.set(key, value);
  }

  onModuleDestroy() {
    (this.cache.store as RedisStore).client.disconnect();
  }
}
