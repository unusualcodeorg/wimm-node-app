import { IsNotEmpty } from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Types } from 'mongoose';

export class SubscriptionResultDto {
  @IsMongoIdObject()
  _id: Types.ObjectId;

  @IsNotEmpty()
  result: string;

  constructor(props: SubscriptionResultDto) {
    Object.assign(this, props);
  }
}
