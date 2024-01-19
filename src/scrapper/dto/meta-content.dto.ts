import {
  IsEnum,
  IsOptional,
  IsUrl,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Category } from '../../content/schemas/content.schema';

export class MetaContentDto {
  @IsEnum(Category)
  category: Category;

  @MinLength(2)
  @MaxLength(500)
  readonly title: string;

  @MinLength(2)
  @MaxLength(100)
  readonly subtitle: string;

  @IsOptional()
  @MinLength(2)
  @MaxLength(2000)
  readonly description: string;

  @IsUrl({ require_tld: false })
  @MaxLength(300)
  readonly thumbnail: string;

  @MaxLength(300)
  readonly extra: string;

  constructor(metaContent: MetaContentDto) {
    Object.assign(this, metaContent);
  }
}
