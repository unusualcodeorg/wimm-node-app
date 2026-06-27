import { registerAs } from '@nestjs/config';
import { DISK_STORAGE_PATH, IMAGE_CACHE_DURATION } from '@/utils';

export const DiskConfigName = 'disk';

export interface DiskConfig {
  path: string;
  imageCacheDuration: number;
}

export default registerAs(DiskConfigName, () => ({
  path: DISK_STORAGE_PATH,
  imageCacheDuration: IMAGE_CACHE_DURATION,
}));
