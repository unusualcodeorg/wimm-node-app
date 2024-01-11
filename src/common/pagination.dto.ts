import { Type } from 'class-transformer';
import { IsInt, Min } from 'class-validator';

export class PaginationDto {
  @IsInt()
  @Min(1)
  @Type(() => Number)
  readonly pageNumber: number;

  @IsInt()
  @Min(1)
  @Type(() => Number)
  readonly pageItemCount: number;
}
