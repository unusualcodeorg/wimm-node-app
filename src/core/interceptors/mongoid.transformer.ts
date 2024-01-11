import {
  BadRequestException,
  ArgumentMetadata,
  ValidationPipe,
} from '@nestjs/common';
import { Types } from 'mongoose';

export class MongoIdTransformerPipe extends ValidationPipe {
  transform(value: any, metadata: ArgumentMetadata): any {
    if (
      metadata.type === 'param' &&
      typeof value === 'string' &&
      metadata.metatype?.name === 'ObjectId'
    ) {
      if (!Types.ObjectId.isValid(value)) {
        const key = metadata?.data ?? '';
        throw new BadRequestException(`${key} must be a mongodb id`);
      }
      return super.transform(new Types.ObjectId(value), metadata);
    }
    return super.transform(value, metadata);
  }
}
