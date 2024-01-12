import { IsBoolean } from 'class-validator';
import { TopicInfoDto } from '../../topic/dto/topic-info.dto';
import { Topic } from '../../topic/schemas/topic.schema';

export class TopicSubscriptionDto extends TopicInfoDto {
  @IsBoolean()
  subscribed: boolean;

  constructor(topic: Topic, subscribed: boolean) {
    super(topic);
    Object.assign(this, { subscribed: subscribed });
  }
}
