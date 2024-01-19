import {
  IsArray,
  IsEnum,
  IsOptional,
  IsUrl,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Category } from '../schemas/content.schema';
import { Types } from 'mongoose';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { Transform } from 'class-transformer';

export class CreateContentDto {
  @IsEnum(Category)
  category: Category;

  @MinLength(3)
  @MaxLength(500)
  readonly title: string;

  @MinLength(3)
  @MaxLength(100)
  readonly subtitle: string;

  @IsOptional()
  @MinLength(3)
  @MaxLength(2000)
  readonly description: string;

  @IsUrl({ require_tld: false })
  @MaxLength(300)
  readonly thumbnail: string;

  @MaxLength(300)
  readonly extra: string;

  @IsOptional()
  @IsArray()
  @IsMongoIdObject({ each: true })
  @Transform(({ value }) =>
    value.map((id: string) =>
      Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : null,
    ),
  )
  readonly topics: Types.ObjectId[];

  @IsOptional()
  @IsArray()
  @IsMongoIdObject({ each: true })
  @Transform(({ value }) =>
    value.map((id: string) =>
      Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : null,
    ),
  )
  readonly mentors: Types.ObjectId[];

  @IsOptional()
  @Min(0)
  @Max(1)
  readonly score: number;

  constructor(params: CreateContentDto) {
    Object.assign(this, params);
  }
}
