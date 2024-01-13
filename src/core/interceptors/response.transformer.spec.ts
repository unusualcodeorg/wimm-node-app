import { CallHandler, ExecutionContext } from '@nestjs/common';
import { DataResponse, MessageResponse, StatusCode } from '../http/response';
import { lastValueFrom, of } from 'rxjs';
import { ResponseTransformer } from './response.transformer';

describe('ResponseTransformerInterceptor', () => {
  let interceptor: ResponseTransformer;
  let context: ExecutionContext;
  let next: CallHandler;

  beforeEach(() => {
    interceptor = new ResponseTransformer();
    context = {} as ExecutionContext;
    next = {
      handle: jest.fn(),
    } as CallHandler;
  });
  it('should transform MessageResponse', async () => {
    const messageResponse = new MessageResponse(StatusCode.SUCCESS, 'Hello');
    jest.spyOn(next, 'handle').mockReturnValue(of(messageResponse));

    const result = await lastValueFrom(interceptor.intercept(context, next));

    expect(result).toBe(messageResponse);
  });

  it('should transform DataResponse', async () => {
    const dataResponse = new DataResponse(StatusCode.SUCCESS, 'success', {
      key: 'value',
    });
    jest.spyOn(next, 'handle').mockReturnValue(of(dataResponse));

    const result = await lastValueFrom(interceptor.intercept(context, next));

    expect(result).toBe(dataResponse);
  });

  it('should transform string to MessageResponse', async () => {
    const plainString = 'Hello, world!';
    jest.spyOn(next, 'handle').mockReturnValue(of(plainString));

    const result = await lastValueFrom(interceptor.intercept(context, next));

    expect(result).toEqual(
      new MessageResponse(StatusCode.SUCCESS, plainString),
    );
  });

  it('should transform other types to DataResponse', async () => {
    const complexObject = { key: 'value' };
    jest.spyOn(next, 'handle').mockReturnValue(of(complexObject));

    const result = await lastValueFrom(interceptor.intercept(context, next));

    expect(result).toEqual(
      new DataResponse(StatusCode.SUCCESS, 'success', complexObject),
    );
  });
});
