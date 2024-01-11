import { IsNotEmpty, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Mentor } from '../schemas/mentor.schema';
import { copy } from '../../common/copier';

export class MentorInfoDto {
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

  constructor(mentor: Mentor) {
    const props = copy(mentor, [
      '_id',
      'name',
      'thumbnail',
      'title',
      'occupation',
      'description',
      'coverImgUrl',
    ]);
    Object.assign(this, props);
  }
}
