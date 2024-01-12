import { IsBoolean, IsEnum } from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Types } from 'mongoose';
import { Category } from '../../content/schemas/content.schema';

export class SubscriptionInfoDto {
  @IsMongoIdObject()
  itemId: Types.ObjectId;

  @IsEnum(Category)
  category: Category;

  @IsBoolean()
  subscribed: boolean;

  constructor(readonly props: Partial<SubscriptionInfoDto>) {
    Object.assign(this, props);
  }
}
