import { OmitType } from '@nestjs/mapped-types';
import { CreateContentDto } from './create-content.dto';

export class CreatePrivateContentDto extends OmitType(CreateContentDto, [
  'mentors',
  'topics',
  'score',
]) {}
