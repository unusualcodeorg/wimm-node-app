import {
  IsOptional,
  IsUrl,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export class CreateTopicDto {
  @MinLength(3)
  @MaxLength(50)
  readonly name: string;

  @MinLength(3)
  @MaxLength(300)
  readonly title: string;

  @MinLength(3)
  @MaxLength(10000)
  readonly description: string;

  @IsUrl({ require_tld: false })
  @MaxLength(300)
  readonly thumbnail: string;

  @IsUrl({ require_tld: false })
  @MaxLength(300)
  readonly coverImgUrl: string;

  @IsOptional()
  @Min(0)
  @Max(1)
  readonly score: number;

  constructor(params: CreateTopicDto) {
    Object.assign(this, params);
  }
}
