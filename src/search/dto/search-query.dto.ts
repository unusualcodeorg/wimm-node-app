import { IsEnum, IsOptional, MaxLength, MinLength } from 'class-validator';
import { Category } from '../../content/schemas/content.schema';

export class SearchQueryDto {
  @MinLength(1)
  @MaxLength(300)
  readonly query: string;

  @IsOptional()
  @IsEnum(Category)
  readonly filter?: Category;
}
