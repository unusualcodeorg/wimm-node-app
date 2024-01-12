import { IsBoolean } from 'class-validator';
import { MentorInfoDto } from '../../mentor/dto/mentor-info.dto';
import { Mentor } from '../../mentor/schemas/mentor.schema';

export class MentorSubscriptionDto extends MentorInfoDto {
  @IsBoolean()
  subscribed: boolean;

  constructor(mentor: Mentor, subscribed: boolean) {
    super(mentor);
    Object.assign(this, { subscribed: subscribed });
  }
}
