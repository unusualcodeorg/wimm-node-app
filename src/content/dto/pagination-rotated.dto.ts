import { Type } from 'class-transformer';
import { IsBoolean, IsInt, IsOptional, Min } from 'class-validator';

export class PaginationRotatedDto {
  @IsOptional()
  @IsBoolean()
  readonly empty: boolean;

  @IsInt()
  @Min(1)
  @Type(() => Number)
  readonly pageNumber: number;

  @IsInt()
  @Min(1)
  @Type(() => Number)
  readonly pageItemCount: number;
}
