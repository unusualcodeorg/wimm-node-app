import { Injectable } from '@nestjs/common';
import axios from 'axios';
import * as cheerio from 'cheerio';
import { Category as ContentCategory } from '../content/schemas/content.schema';
import { MetaContentDto } from './dto/meta-content.dto';

@Injectable()
export class ScrapperService {
  async scrape(url: string) {
    const response = await axios.get(url);
    const $ = cheerio.load(response.data);

    const website = new URL(url).hostname;

    const title = $('title').text();
    const description = $('meta[name="description"]').attr('content');
    const author = $('meta[name="author"]').attr('content');
    const thumbnail = $('meta[property="og:image"]').attr('content');
    const publisher = $('meta[property="og:site_name"]').attr('content');

    let category = ContentCategory.ARTICLE;

    if (website.includes('youtu.be') || website.includes('youtube')) {
      category = ContentCategory.YOUTUBE;
    }

    const data: MetaContentDto = new MetaContentDto({
      category: category,
      title: title,
      subtitle: author ? author : publisher ? publisher : website,
      description: description ? description : title,
      thumbnail: thumbnail ? thumbnail : 'http://localhost/dummy.png',
      extra: url,
    });

    return data;
  }
}
