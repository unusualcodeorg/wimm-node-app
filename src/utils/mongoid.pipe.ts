import {
  PipeTransform,
  Injectable,
  BadRequestException,
  ArgumentMetadata,
} from '@nestjs/common';
import { Types } from 'mongoose';

@Injectable()
export class MongoIdValidationPipe implements PipeTransform<string> {
  transform(value: string, metadata: ArgumentMetadata): string {
    if (!Types.ObjectId.isValid(value)) {
      const key = metadata?.data ?? '';
      throw new BadRequestException(`${key} is invalid`);
    }
    return value;
  }
}
