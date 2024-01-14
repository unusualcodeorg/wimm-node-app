import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheConfig, CacheConfigName } from '../config/cache.config';
import { redisStore } from './redis-cache';
import { CacheModuleOptions, CacheOptionsFactory } from '@nestjs/cache-manager';

@Injectable()
export class CacheConfigFactory implements CacheOptionsFactory {
  constructor(private readonly configService: ConfigService) {}

  async createCacheOptions(): Promise<CacheModuleOptions> {
    const cacheConfig =
      this.configService.getOrThrow<CacheConfig>(CacheConfigName);
    const redisURL = `redis://:${cacheConfig.password}@${cacheConfig.host}:${cacheConfig.port}`;
    return {
      store: redisStore,
      url: redisURL,
      ttl: cacheConfig.ttl,
    };
  }
}
