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
    return {
      store: redisStore,
      host: cacheConfig.host,
      port: cacheConfig.host,
      ttl: cacheConfig.ttl,
      // password: cacheConfig.password,
    };
  }
}
