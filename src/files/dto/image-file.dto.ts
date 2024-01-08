import { IsNotEmpty, MaxLength } from 'class-validator';

export class ImageFileDto {
  @IsNotEmpty()
  @MaxLength(1000)
  readonly name: string;
}
