import { IsNotEmpty, IsOptional, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Mentor } from '../schemas/mentor.schema';
import { copy } from '../../common/copier';

export class MentorInfoDto {
  @IsMongoIdObject()
  _id: Types.ObjectId;

  @IsNotEmpty()
  name: string;

  @IsUrl({ require_tld: false })
  thumbnail: string;

  @IsNotEmpty()
  occupation: string;

  @IsNotEmpty()
  title: string;

  @IsOptional()
  @IsNotEmpty()
  description: string;

  @IsUrl({ require_tld: false })
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
