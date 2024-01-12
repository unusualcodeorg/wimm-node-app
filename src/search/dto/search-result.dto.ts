import { IsEnum, IsNotEmpty, IsUrl } from 'class-validator';
import { Types } from 'mongoose';
import { Category } from '../../content/schemas/content.schema';
import { IsMongoIdObject } from '../../common/mongo.validation';

export class SearchResultDto {
  @IsMongoIdObject()
  id: Types.ObjectId;

  @IsNotEmpty()
  title: string;

  @IsEnum(Category)
  category: Category;

  @IsUrl({ require_tld: false })
  thumbnail: string;

  @IsNotEmpty()
  extra: string;

  constructor(props: SearchResultDto) {
    Object.assign(this, props);
  }
}
