import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  InternalServerErrorException,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { ValidationError, validateSync } from 'class-validator';

@Injectable()
export class ResponseValidation implements NestInterceptor {
  intercept(_: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((data) => {
        if (Array.isArray(data)) {
          data.forEach((item) => {
            if (item instanceof Object) this.validate(item);
          });
        } else if (data instanceof Object) {
          this.validate(data);
        }
        return data;
      }),
    );
  }

  private validate(data: any) {
    const errors = validateSync(data);
    if (errors.length > 0) {
      const messages = this.extractErrorMessages(errors);
      throw new InternalServerErrorException([
        'Response validation failed',
        ...messages,
      ]);
    }
  }

  private extractErrorMessages(
    errors: ValidationError[],
    messages: string[] = [],
  ): string[] {
    for (const error of errors) {
      if (error) {
        if (error.children && error.children.length > 0)
          this.extractErrorMessages(error.children, messages);
        const constraints = error.constraints;
        if (constraints) messages.push(Object.values(constraints).join(', '));
      }
    }
    return messages;
  }
}
