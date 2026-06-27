import { registerAs } from '@nestjs/config';
import { NODE_ENV, PORT, TZ, LOG_DIR } from '@/utils';

export const ServerConfigName = 'server';

export interface ServerConfig {
  nodeEnv: string;
  port: number;
  timezone: string;
  logDirectory: string;
}

export default registerAs(ServerConfigName, () => ({
  nodeEnv: NODE_ENV,
  port: PORT,
  timezone: TZ,
  logDirectory: LOG_DIR,
}));
