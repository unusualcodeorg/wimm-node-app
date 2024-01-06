import { IsNotEmpty, MaxLength } from 'class-validator';

export class CreateMessageDto {
  @IsNotEmpty()
  readonly type: string;

  @IsNotEmpty()
  @MaxLength(1000)
  readonly message: string;
}
