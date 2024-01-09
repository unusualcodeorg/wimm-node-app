import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, map } from 'rxjs';
import { DataResponse, MessageResponse, StatusCode } from '../http/response';

@Injectable()
export class ResponseTransformer implements NestInterceptor {
  intercept(_: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((data) => {
        if (data instanceof MessageResponse) return data;
        if (data instanceof DataResponse) return data;
        if (typeof data == 'string')
          return new MessageResponse(StatusCode.SUCCESS, data);
        return new DataResponse(StatusCode.SUCCESS, 'success', data);
      }),
    );
  }
}
