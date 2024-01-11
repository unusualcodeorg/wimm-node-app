import { IsNotEmpty, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { copy } from '../../common/copier';
import { Topic } from '../schemas/topic.schema';

export class TopicInfoDto {
  @IsMongoIdObject()
  _id: Types.ObjectId;

  @IsNotEmpty()
  name: string;

  @IsUrl()
  thumbnail: string;

  @IsNotEmpty()
  occupation: string;

  @IsNotEmpty()
  title: string;

  @IsNotEmpty()
  description: string;

  @IsUrl()
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
