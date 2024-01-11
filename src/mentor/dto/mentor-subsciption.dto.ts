import { IsBoolean } from 'class-validator';
import { Mentor } from '../schemas/mentor.schema';
import { MentorInfoDto } from './mentor-info.dto';

export class MentorSubscriptionDto extends MentorInfoDto {
  @IsBoolean()
  subscribed: boolean;

  constructor(mentor: Mentor, subscribed: boolean) {
    super(mentor);
    Object.assign(this, { subscribed: subscribed });
  }
}
