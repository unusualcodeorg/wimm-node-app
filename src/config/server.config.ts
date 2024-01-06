import { registerAs } from '@nestjs/config';

export const ServerConfigName = 'server';

export interface ServerConfig {
  port: number;
}

export default registerAs(ServerConfigName, () => ({
  port: parseInt(process.env.PORT || '3000'),
}));
