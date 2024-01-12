import { IsNotEmpty, IsOptional, IsUrl } from 'class-validator';

export class MetaContentEntity {
  @IsNotEmpty()
  category: string;

  @IsOptional()
  title?: string;

  @IsOptional()
  subtitle?: string;

  @IsOptional()
  description?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  thumbnail?: string;

  @IsNotEmpty()
  extra: string;

  constructor(metaContent: MetaContentEntity) {
    Object.assign(this, metaContent);
  }
}
