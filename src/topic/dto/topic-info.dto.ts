import { IsNotEmpty, IsOptional, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { copy } from '../../common/copier';
import { Topic } from '../schemas/topic.schema';

export class TopicInfoDto {
  @IsMongoIdObject()
  _id: Types.ObjectId;

  @IsNotEmpty()
  name: string;

  @IsNotEmpty()
  title: string;

  @IsOptional()
  @IsNotEmpty()
  description: string;

  @IsUrl({ require_tld: false })
  thumbnail: string;

  @IsUrl({ require_tld: false })
  coverImgUrl: string;

  constructor(topic: Topic) {
    const props = copy(topic, [
      '_id',
      'name',
      'thumbnail',
      'title',
      'description',
      'coverImgUrl',
    ]);
    Object.assign(this, props);
  }
}
