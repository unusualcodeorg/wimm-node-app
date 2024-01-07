// exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { TokenExpiredError } from '@nestjs/jwt';
import { Request, Response } from 'express';
import { StatusCode } from '../http/response';

@Catch()
export class ExpectionHandler implements ExceptionFilter {
  catch(exception: any, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let statusCode = StatusCode.FAILURE;
    let message: string = 'Something went wrong';

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'string') {
        message = body;
      } else if ('message' in body && typeof body.message === 'string') {
        message = body.message;
      }
    } else if (exception instanceof TokenExpiredError) {
      status = HttpStatus.UNAUTHORIZED;
      statusCode = StatusCode.INVALID_ACCESS_TOKEN;
      response.appendHeader('instruction', 'refresh_token');
      message = 'Token Expired';
    }

    response.status(status).json({
      status: status,
      statusCode: statusCode,
      message: message,
      url: request.url,
    });
  }
}
