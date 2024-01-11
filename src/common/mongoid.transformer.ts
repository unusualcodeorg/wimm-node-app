import {
  PipeTransform,
  Injectable,
  BadRequestException,
  ArgumentMetadata,
} from '@nestjs/common';
import { Types } from 'mongoose';

@Injectable()
export class MongoIdTransformer implements PipeTransform<any> {
  transform(value: any, metadata: ArgumentMetadata): any {
    if (typeof value !== 'string') return value;

    if (metadata.metatype?.name === 'ObjectId') {
      if (!Types.ObjectId.isValid(value)) {
        const key = metadata?.data ?? '';
        throw new BadRequestException(`${key} must be a mongodb id`);
      }
      return new Types.ObjectId(value);
    }

    return value;
  }
}
