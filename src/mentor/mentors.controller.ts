import { Controller, Get, Query } from '@nestjs/common';
import { MentorService } from './mentor.service';
import { MentorInfoDto } from './dto/mentor-info.dto';
import { PaginationDto } from '../common/pagination.dto';

@Controller('mentors')
export class MentorsController {
  constructor(private readonly mentorService: MentorService) {}

  @Get('latest')
  async findLatest(
    @Query() paginationDto: PaginationDto,
  ): Promise<MentorInfoDto[]> {
    const mentors =
      await this.mentorService.findMentorsPaginated(paginationDto);
    return mentors.map((mentor) => new MentorInfoDto(mentor));
  }

  @Get('recommendation')
  async findRecomended(
    @Query() paginationDto: PaginationDto,
  ): Promise<MentorInfoDto[]> {
    const mentors =
      await this.mentorService.findRecommendedMentorsPaginated(paginationDto);
    return mentors.map((mentor) => new MentorInfoDto(mentor));
  }
}
