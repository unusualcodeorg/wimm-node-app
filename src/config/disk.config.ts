import { registerAs } from '@nestjs/config';

export const DiskConfigName = 'disk';

export interface DiskConfig {
  path: string;
  imageCacheDuration: number;
}

export default registerAs(DiskConfigName, () => ({
  path: process.env.DISK_STORAGE_PATH || 'disk',
  imageCacheDuration: process.env.IMAGE_CACHE_DURATION || 31536000, // 1yr
}));
