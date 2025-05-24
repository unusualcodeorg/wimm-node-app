import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Inject, Injectable } from '@nestjs/common';
import { Cache } from 'cache-manager';

@Injectable()
export class CacheService {
  constructor(@Inject(CACHE_MANAGER) private readonly cache: Cache) {}

  async getValue<T>(key: string): Promise<T | null> {
    return await this.cache.get(key);
  }

  async setValue(key: string, value: string): Promise<void> {
    await this.cache.set(key, value);
  }

  async delete(key: string): Promise<void> {
    await this.cache.del(key);
  }

  onModuleDestroy() {
    this.cache.disconnect();
  }
}
