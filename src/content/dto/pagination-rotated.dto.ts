import { IsBoolean, IsOptional } from 'class-validator';
import { PaginationDto } from '../../common/pagination.dto';
import { Type } from 'class-transformer';

export class PaginationRotatedDto extends PaginationDto {
  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  readonly empty: boolean = false;
}
