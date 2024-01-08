import { registerAs } from '@nestjs/config';

export const DiskConfigName = 'disk';

export interface DiskConfig {
  path: string;
}

export default registerAs(DiskConfigName, () => ({
  path: process.env.DISK_STORAGE_PATH || 'disk',
}));
