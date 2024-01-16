import { Transform } from 'class-transformer';
import { Types } from 'mongoose';
import { IsMongoIdObject } from './mongo.validation';
import { IsNotEmpty } from 'class-validator';

export class MongoIdDto {
  @IsNotEmpty()
  @Transform(({ value }) => {
    if (Types.ObjectId.isValid(value)) return new Types.ObjectId(value);
    return null;
  })
  @IsMongoIdObject()
  readonly id: Types.ObjectId;

  constructor(props: MongoIdDto) {
    Object.assign(this, props);
  }
}
