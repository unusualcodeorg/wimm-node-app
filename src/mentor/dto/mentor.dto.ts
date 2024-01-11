import { IsBoolean, IsNotEmpty, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../core/validations/mongo.validation';
import { Mentor } from '../schemas/mentor.schema';
import { copy } from '../../utils/copier';

export class MentorDto {
  @IsMongoIdObject()
  _id: Types.ObjectId;

  @IsBoolean()
  subscribed: boolean;

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

  constructor(mentor: Mentor, subscribed: boolean) {
    const props = copy(mentor, [
      '_id',
      'name',
      'thumbnail',
      'title',
      'occupation',
      'description',
      'coverImgUrl',
    ]);
    Object.assign(this, { ...props, subscribed: subscribed });
  }
}
