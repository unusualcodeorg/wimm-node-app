export enum StatusCode {
  SUCCESS = 10000,
  FAILURE = 10001,
  RETRY = 10002,
  INVALID_ACCESS_TOKEN = 10003,
}

export class DataResponse<T> {
  readonly statusCode: StatusCode;

  readonly message: string;

  readonly data: T;

  constructor(statusCode: StatusCode, message: string, data: T) {
    this.statusCode = statusCode;
    this.message = message;
    this.data = data;
  }
}

export class MessageResponse {
  readonly statusCode: StatusCode;

  readonly message: string;

  constructor(statusCode: StatusCode, message: string) {
    this.statusCode = statusCode;
    this.message = message;
  }
}
