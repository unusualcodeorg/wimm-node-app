// exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
import { TokenExpiredError } from '@nestjs/jwt';
import { Request, Response } from 'express';
import { StatusCode } from '../http/response';
import { isArray } from 'class-validator';
import { ConfigService } from '@nestjs/config';
import { ServerConfig, ServerConfigName } from '../../config/server.config';
import { WinstonLogger } from '../../setup/winston.logger';

@Catch()
export class ExpectionHandler implements ExceptionFilter {
  constructor(
    private readonly configService: ConfigService,
    private readonly logger: WinstonLogger,
  ) {}

  catch(exception: any, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let statusCode = StatusCode.FAILURE;
    let message: string = 'Something went wrong';
    let errors: any[] | undefined = undefined;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'string') {
        message = body;
      } else if ('message' in body) {
        if (typeof body.message === 'string') {
          message = body.message;
        } else if (isArray(body.message) && body.message.length > 0) {
          message = body.message[0];
          errors = body.message;
        }
      }
      if (exception instanceof InternalServerErrorException) {
        this.logger.error(exception.message, exception.stack);
      }

      if (exception instanceof UnauthorizedException) {
        if (message.toLowerCase().includes('invalid access token')) {
          statusCode = StatusCode.INVALID_ACCESS_TOKEN;
          response.appendHeader('instruction', 'logout');
        }
      }
    } else if (exception instanceof TokenExpiredError) {
      status = HttpStatus.UNAUTHORIZED;
      statusCode = StatusCode.INVALID_ACCESS_TOKEN;
      response.appendHeader('instruction', 'refresh_token');
      message = 'Token Expired';
    } else {
      const serverConfig =
        this.configService.getOrThrow<ServerConfig>(ServerConfigName);
      if (serverConfig.nodeEnv === 'development') message = exception.message;
      this.logger.error(exception.message, exception.stack);
    }

    response.status(status).json({
      statusCode: statusCode,
      message: message,
      errors: errors,
      url: request.url,
    });
  }
}
