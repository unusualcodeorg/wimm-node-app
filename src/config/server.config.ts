import { registerAs } from '@nestjs/config';

export const ServerConfigName = 'server';

export interface ServerConfig {
  nodeEnv: string;
  port: number;
  timezone: string;
}

export default registerAs(ServerConfigName, () => ({
  nodeEnv: process.env.NODE_ENV,
  port: parseInt(process.env.PORT || '3000'),
  timezone: process.env.TZ,
}));
