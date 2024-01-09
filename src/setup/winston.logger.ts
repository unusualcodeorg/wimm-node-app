import { Injectable, LoggerService } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as winston from 'winston';
import * as DailyRotateFile from 'winston-daily-rotate-file';
import { ServerConfig, ServerConfigName } from '../config/server.config';
import { resolve } from 'path';

@Injectable()
export class WinstonLogger implements LoggerService {
  private readonly logger: winston.Logger;

  constructor(private readonly configService: ConfigService) {
    const serverConfig =
      this.configService.getOrThrow<ServerConfig>(ServerConfigName);
    const logsPath = resolve(__dirname, '../..', serverConfig.logDirectory);

    const logLevel = serverConfig.nodeEnv === 'development' ? 'debug' : 'warn';

    const dailyRotateFile = new DailyRotateFile({
      level: logLevel,
      dirname: logsPath,
      filename: '%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      zippedArchive: true,
      handleExceptions: true,
      maxSize: '20m',
      maxFiles: '14d',
    });

    this.logger = winston.createLogger({
      level: logLevel,
      format: winston.format.combine(
        winston.format.errors({ stack: true }),
        winston.format.timestamp(),
        winston.format.json(),
      ),
      transports: [
        new winston.transports.Console({
          level: logLevel,
          format: winston.format.combine(
            winston.format.errors({ stack: true }),
            winston.format.prettyPrint(),
          ),
        }),
        dailyRotateFile,
      ],
      exceptionHandlers: [dailyRotateFile],
      exitOnError: false, // do not exit on handled exceptions
    });
  }

  log(message: string) {
    this.logger.info(message);
  }

  error(message: string, trace: string) {
    this.logger.error(message, trace);
  }

  warn(message: string) {
    this.logger.warn(message);
  }

  debug(message: string) {
    this.logger.debug(message);
  }

  verbose(message: string) {
    this.logger.verbose(message);
  }
}
