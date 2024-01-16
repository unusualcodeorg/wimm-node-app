import { IsArray, IsOptional } from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Transform } from 'class-transformer';
import { Types } from 'mongoose';

export class SubscriptionDto {
  @IsOptional()
  @IsArray()
  @IsMongoIdObject({ each: true })
  @Transform(({ value }) =>
    value.map((id: string) =>
      Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : null,
    ),
  )
  readonly mentorIds: Types.ObjectId[] | undefined;

  @IsOptional()
  @IsArray()
  @IsMongoIdObject({ each: true })
  @Transform(({ value }) =>
    value.map((id: string) =>
      Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : null,
    ),
  )
  readonly topicIds: Types.ObjectId[] | undefined;

  constructor(props: SubscriptionDto) {
    Object.assign(this, props);
  }
}
